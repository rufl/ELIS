MR_RESCUE_SOFTWARE_PROOF_V1
status=passed
source_commit=eea134445474ff0b5bc9c792f777caee8b0c90fc
checked_utc=2026-09-29T15:16:34Z
commands=
  bash scripts/mr_rescue_smoke.sh
  python3 scripts/test_package_mr_rescue_playtest.py
  python3 scripts/test_mr_rescue_hardware_gate.py
results=
  Mr. Rescue release audit: pass (13374088 payload bytes)
  Mr. Rescue profile/core/scoring/enemy/three-boss behavior+victory stress: pass
  package tests: 15 passed
  hardware-proof validator tests: 14 passed
scope=desktop/package/proof-record validation only
hardware_status=open
hardware_unblock=named-board frame-time, memory, and 30-minute soak record
