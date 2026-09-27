#!/usr/bin/env python3
"""Focused boundary tests for the Mr. Rescue hardware proof validator."""

from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from mr_rescue_hardware_gate import ProofError, validate_record  # noqa: E402


class HardwareGateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mr-rescue-hardware-gate-")
        root = Path(self.temporary.name)
        self.cartridge = root / "mr-rescue.lupi"
        self.cartridge.write_bytes(b"deterministic cartridge fixture\n")
        self.evidence = {}
        for name in ("frame_time", "memory", "soak"):
            path = root / f"{name}.log"
            path.write_text(f"{name} evidence\n", encoding="utf-8")
            self.evidence[name] = str(path)
        self.record = {
            "schema": "elis.mr-rescue-hardware/v1",
            "board": {
                "name": "Lupi-Validation-01",
                "firmware": "firmware-commit",
                "build_config": "release-lupi-n16r8",
                "measurement_tool": "board-probe-1",
            },
            "source_commit": "source-commit",
            "started_at": "2026-09-27T12:00:00Z",
            "ended_at": "2026-09-27T12:31:00Z",
            "cartridge": {
                "sha256": hashlib.sha256(self.cartridge.read_bytes()).hexdigest(),
                "size_bytes": self.cartridge.stat().st_size,
            },
            "measurements": {
                "frame_time_ms": [16.0, 15.7, 16.2],
                "lua_memory_bytes": [900_000, 1_100_000, 1_000_000],
                "manifest_exact": True,
                "max_bitmap_pixels": 49_152,
            },
            "soak": {
                "duration_seconds": 1_800,
                "crash": False,
                "reset": False,
                "input_lockup": False,
                "renderer_corruption": False,
                "memory_growth": False,
            },
            "evidence": self.evidence,
        }

    def tearDown(self):
        self.temporary.cleanup()

    def test_valid_record_binds_measurements_to_cartridge(self):
        proof = validate_record(self.record, self.cartridge)
        self.assertEqual(proof["status"], "passed")
        self.assertEqual(proof["cartridge"]["size_bytes"], self.cartridge.stat().st_size)
        self.assertEqual(proof["measurements"]["frame_time_ms"]["worst"], 16.2)
        self.assertEqual(proof["measurements"]["lua_memory_bytes"]["peak"], 1_100_000)

    def test_proof_records_raw_evidence_digests(self):
        proof = validate_record(self.record, self.cartridge)
        for name, raw_path in self.evidence.items():
            path = Path(raw_path)
            details = proof["evidence"][name]
            self.assertEqual(details["path"], str(path.resolve()))
            self.assertEqual(details["sha256"], hashlib.sha256(path.read_bytes()).hexdigest())
            self.assertEqual(details["size_bytes"], path.stat().st_size)

    def test_hash_mismatch_is_rejected(self):
        record = copy.deepcopy(self.record)
        record["cartridge"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ProofError, "hash mismatch"):
            validate_record(record, self.cartridge)

    def test_frame_time_boundary_is_rejected(self):
        record = copy.deepcopy(self.record)
        record["measurements"]["frame_time_ms"] = [16.667, 16.668]
        with self.assertRaisesRegex(ProofError, "frame time"):
            validate_record(record, self.cartridge)

    def test_memory_boundary_is_rejected(self):
        record = copy.deepcopy(self.record)
        record["measurements"]["lua_memory_bytes"] = [1, 4 * 1024 * 1024 + 1]
        with self.assertRaisesRegex(ProofError, "Lua memory"):
            validate_record(record, self.cartridge)

    def test_short_or_failed_soak_is_rejected(self):
        record = copy.deepcopy(self.record)
        record["soak"]["duration_seconds"] = 1_799
        with self.assertRaisesRegex(ProofError, "soak duration"):
            validate_record(record, self.cartridge)
        record = copy.deepcopy(self.record)
        record["soak"]["renderer_corruption"] = True
        with self.assertRaisesRegex(ProofError, "renderer_corruption"):
            validate_record(record, self.cartridge)

    def test_evidence_interval_must_cover_soak(self):
        record = copy.deepcopy(self.record)
        record["ended_at"] = "2026-09-27T12:01:00Z"
        with self.assertRaisesRegex(ProofError, "evidence interval"):
            validate_record(record, self.cartridge)
        record = copy.deepcopy(self.record)
        record["ended_at"] = record["started_at"]
        with self.assertRaisesRegex(ProofError, "ended_at"):
            validate_record(record, self.cartridge)


    def test_timestamps_require_timezone_offsets(self):
        record = copy.deepcopy(self.record)
        record["started_at"] = "2026-09-27T12:00:00"
        with self.assertRaisesRegex(ProofError, "timezone offset"):
            validate_record(record, self.cartridge)
        record = copy.deepcopy(self.record)
        record["ended_at"] = "2026-09-27"
        with self.assertRaisesRegex(ProofError, "timezone offset"):
            validate_record(record, self.cartridge)

    def test_cli_writes_immutable_proof(self):
        root = Path(self.temporary.name)
        record_path = root / "raw.json"
        output_path = root / "proof.json"
        record_path.write_text(json.dumps(self.record), encoding="utf-8")
        command = [
            sys.executable,
            str(ROOT / "scripts/mr_rescue_hardware_gate.py"),
            "--record",
            str(record_path),
            "--cartridge",
            str(self.cartridge),
            "--output",
            str(output_path),
        ]
        first = subprocess.run(command, capture_output=True, text=True, check=False)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(json.loads(output_path.read_text())["status"], "passed")
        original = output_path.read_bytes()
        second = subprocess.run(command, capture_output=True, text=True, check=False)
        self.assertNotEqual(second.returncode, 0)
        self.assertEqual(output_path.read_bytes(), original)

    def test_missing_raw_evidence_is_rejected(self):
        record = copy.deepcopy(self.record)
        record["evidence"]["memory"] = str(Path(self.temporary.name) / "missing.log")
        with self.assertRaisesRegex(ProofError, "evidence.memory"):
            validate_record(record, self.cartridge)


if __name__ == "__main__":
    unittest.main()
