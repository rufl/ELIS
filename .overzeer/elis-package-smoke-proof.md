ELIS_PACKAGE_SMOKE_PROOF_V1
status=passed
source_commit=68eba024d354c2600f6993db3117541563cad311
ci_build_run=https://github.com/rufl/ELIS/actions/runs/36869449154
ci_verify_run=https://github.com/rufl/ELIS/actions/runs/36869449140
release=v0.1.0-rc.11
release_workflow_run=https://github.com/rufl/ELIS/actions/runs/36869479011
checked_utc=2026-10-01T13:55:42Z
contract=--package-smoke
  gh workflow run Binaries --ref main --field version=0.1.0-rc.11 --field publish=true
  sha256sum -c SHA256SUMS
  tools/zeer-dogfood-deploy.sh preview/deploy for ddjarin and chopper
  receiver /api/deployments provenance verification
results=
  Linux build: pass
  Windows build: pass
  extracted Linux smoke including --package-smoke: pass
  extracted Windows smoke including --package-smoke: pass
  Verify: pass
  rc.11 release archives, per-target manifests, aggregate ZTASH manifest, and SHA256SUMS: pass
  ZTASH immutable preview for ddjarin/windows-x86_64 and chopper/linux-x86_64: pass
scope=release-package and deployment-smoke contract only
hardware_status=not applicable
deployment_release=v0.1.0-rc.11
deployment_preview=passed: exact rc.11 archives matched SHA256SUMS and target-bound metadata before mutation
deployment_ddjarin=passed: authenticated ZEER deployment completed; deployment_id=1d065714eea7d1360d0a8e24f44ced8d version=0.1.0-rc.11 build_id=68eba024d354c2600f6993db3117541563cad311 sha256=a7edd802fc8732c682a3958b5312e58b79bb23baf951d3e3265a9ad5e8f892af size=127727035 active=true freshness=current
deployment_chopper=passed: authenticated ZEER deployment completed; deployment_id=deef069c3e5f4f96afef3cbedd26401c version=0.1.0-rc.11 build_id=68eba024d354c2600f6993db3117541563cad311 sha256=df6b164bbaf591b2f00c77ddac1d40b768c0c48d05580ebecd0430bc9ae84369 size=2376198 active=true freshness=current
deployment_unblock=none: both configured receivers report the requested version, build_id, SHA-256, size, active=true, and freshness=current
