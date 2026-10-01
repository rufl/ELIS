ELIS_PACKAGE_SMOKE_PROOF_V1
status=passed
source_commit=87b5d379d77b0535fcf04dc80a3c15279ad291c0
ci_build_run=https://github.com/rufl/ELIS/actions/runs/36861519466
ci_verify_run=https://github.com/rufl/ELIS/actions/runs/36861519499
release=v0.1.0-rc.10
release_workflow_run=https://github.com/rufl/ELIS/actions/runs/36864402637
checked_utc=2026-10-01T13:01:16Z
contract=--package-smoke
  gh workflow run Binaries --ref main --field version=0.1.0-rc.10 --field publish=true
  sha256sum -c SHA256SUMS
  tools/zeer-dogfood-deploy.sh preview/deploy for ddjarin and chopper
  receiver /api/deployments provenance verification
results=
  Linux build: pass
  Windows build: pass
  extracted Linux smoke including --package-smoke: pass
  extracted Windows smoke including --package-smoke: pass
  Verify: pass
  rc.10 release archives, per-target manifests, aggregate ZTASH manifest, and SHA256SUMS: pass
  ZTASH immutable preview for ddjarin/windows-x86_64 and chopper/linux-x86_64: pass
scope=release-package and deployment-smoke contract only
hardware_status=not applicable
deployment_release=v0.1.0-rc.10
deployment_preview=passed: exact rc.10 archives matched SHA256SUMS and target-bound metadata before mutation
deployment_ddjarin=passed: authenticated ZEER deployment completed; deployment_id=880206759c0d813b222029eec0cb3cf2 version=0.1.0-rc.10 build_id=87b5d379d77b0535fcf04dc80a3c15279ad291c0 sha256=f8038190451b0f6851d4019357e26c30b05d4de5554be712c51afff316a66209 size=127727009 active=true freshness=current
deployment_chopper=passed: authenticated ZEER deployment completed; deployment_id=307a5f393e4c7a2a57280e3ce2e44cf1 version=0.1.0-rc.10 build_id=87b5d379d77b0535fcf04dc80a3c15279ad291c0 sha256=9df874ea2707180e3491b5cd8609ed1df492bcbacaecfa1d806108018d97ae04 size=2376177 active=true freshness=current
deployment_unblock=none: both configured receivers report the requested version, build_id, SHA-256, size, active=true, and freshness=current
