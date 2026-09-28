MR_RESCUE_SOFTWARE_PROOF_V1
status=passed
source_commit=9ce0f276412e8366623ce0e1523c413c0db69868
checked_utc=2026-09-28T13:48:21Z
commands=
  bash scripts/mr_rescue_smoke.sh
  python3 scripts/test_package_mr_rescue_playtest.py
  python3 scripts/test_mr_rescue_hardware_gate.py
results=
  Mr. Rescue release audit: pass (13374088 payload bytes)
  Mr. Rescue profile/core/scoring/enemy/three-boss behavior+victory stress: pass
  package tests: 15 passed
  hardware-proof validator tests: 13 passed
scope=desktop/package/proof-record validation only
hardware_status=open
hardware_unblock=named-board frame-time, memory, and 30-minute soak record
