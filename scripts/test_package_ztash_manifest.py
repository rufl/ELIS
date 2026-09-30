#!/usr/bin/env python3
"""Focused regressions for ELIS ZTASH release manifests."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import package_ztash_manifest as ztash  # noqa: E402


VERSION = "0.1.0-rc.9"
COMMIT = "4b99771efcb00c4cba11026386b6a0b6858b1fcf"


class ZtashManifestTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="elis-ztash-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.linux = self.root / f"elis-{VERSION}-linux-x86_64.tar.gz"
        self.windows = self.root / f"elis-{VERSION}-windows-x86_64.zip"
        self.linux.write_bytes(b"linux release archive\n")
        self.windows.write_bytes(b"windows release archive\n")

    def artifacts(self):
        return {
            "x86_64-linux": self.linux,
            "x86_64-windows-gnu": self.windows,
        }

    def test_manifest_binds_both_archives_to_one_source_commit(self):
        manifest = ztash.build_manifest(VERSION, COMMIT, COMMIT, 1_790_000_000, self.artifacts())
        self.assertEqual(manifest["schema"], "ztash-release-v1")
        self.assertEqual(manifest["application"], "elis")
        self.assertEqual(manifest["build_id"], COMMIT)
        self.assertEqual(manifest["source_commit"], COMMIT)
        entries = {entry["target"]: entry for entry in manifest["artifacts"]}
        self.assertEqual(set(entries), {"x86_64-linux", "x86_64-windows-gnu"})
        self.assertEqual(entries["x86_64-linux"]["name"], self.linux.name)
        self.assertEqual(entries["x86_64-linux"]["size_bytes"], self.linux.stat().st_size)
        self.assertEqual(
            entries["x86_64-windows-gnu"]["sha256"],
            hashlib.sha256(self.windows.read_bytes()).hexdigest(),
        )

        with self.assertRaisesRegex(ValueError, "explicit semantic prerelease"):
            ztash.build_manifest("0.1.0", COMMIT, COMMIT, 1, self.artifacts())

    def test_manifest_rejects_incomplete_misnamed_and_symlinked_inputs(self):
        incomplete = self.artifacts()
        del incomplete["x86_64-windows-gnu"]
        with self.assertRaisesRegex(ValueError, "exactly the Linux and Windows"):
            ztash.build_manifest(VERSION, COMMIT, COMMIT, 1, incomplete)

        misnamed = self.root / "mutable-latest.zip"
        misnamed.write_bytes(self.windows.read_bytes())
        wrong_name = self.artifacts()
        wrong_name["x86_64-windows-gnu"] = misnamed
        with self.assertRaisesRegex(ValueError, "Unexpected x86_64-windows-gnu archive name"):
            ztash.build_manifest(VERSION, COMMIT, COMMIT, 1, wrong_name)

        symlink = self.root / self.windows.name
        self.windows.rename(self.root / "windows-payload.zip")
        symlink.symlink_to(self.root / "windows-payload.zip")
        with self.assertRaisesRegex(ValueError, "regular non-symlink"):
            ztash.build_manifest(VERSION, COMMIT, COMMIT, 1, self.artifacts())

    def test_manifest_publication_is_no_replace(self):
        manifest = ztash.build_manifest(VERSION, COMMIT, COMMIT, 1, self.artifacts())
        output = self.root / "ztash-release.json"
        ztash.write_manifest(output, manifest)
        self.assertEqual(json.loads(output.read_text(encoding="utf-8")), manifest)
        with self.assertRaisesRegex(ValueError, "Refusing to replace"):
            ztash.write_manifest(output, manifest)

    def test_workflow_cli_writes_and_refuses_to_replace_manifest(self):
        output = self.root / "ztash-release.json"
        command = [
            sys.executable,
            str(ROOT / "scripts/package_ztash_manifest.py"),
            "--version",
            VERSION,
            "--build-id",
            COMMIT,
            "--source-commit",
            COMMIT,
            "--source-date-epoch",
            "1790000000",
            "--artifact",
            f"x86_64-linux={self.linux}",
            "--artifact",
            f"x86_64-windows-gnu={self.windows}",
            "--output",
            str(output),
        ]
        first = subprocess.run(command, text=True, capture_output=True, check=False)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(first.stdout.strip(), str(output))
        self.assertEqual(json.loads(output.read_text(encoding="utf-8"))["source_commit"], COMMIT)

        second = subprocess.run(command, text=True, capture_output=True, check=False)
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("Refusing to replace ZTASH manifest", second.stderr)


if __name__ == "__main__":
    unittest.main()
