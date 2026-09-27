MR_RESCUE_SOFTWARE_PROOF_V1
status=passed
source_commit=bbee8623d994ad9e3d996719fca36dc5afe5da50
checked_utc=2026-09-27
commands=
  bash scripts/mr_rescue_smoke.sh
  python3 scripts/test_package_mr_rescue_playtest.py
  python3 scripts/test_mr_rescue_hardware_gate.py
results=
  Mr. Rescue release audit: pass (13374088 payload bytes)
  Mr. Rescue profile/core/scoring/enemy/three-boss behavior+victory stress: pass
  package tests: 15 passed
  hardware-proof validator tests: 8 passed
scope=desktop/package/proof-record validation only
hardware_status=open
hardware_unblock=named-board frame-time, memory, and 30-minute soak record
