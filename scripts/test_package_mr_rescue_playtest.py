#!/usr/bin/env python3
"""Focused, display-free regressions for the transferable playtest artifacts."""

import hashlib
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile

from package_release import ROOT, archive_payload
from package_mr_rescue_playtest import ATTRIBUTION, OUTPUTS, PORT


class PlaytestPackaging(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="elis-playtest-package-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def package(self, output, script=None, replace=False):
        command = [sys.executable, str(script or ROOT / "scripts/package_mr_rescue_playtest.py"),
                   "--output", str(output)]
        if replace:
            command.append("--replace")
        return subprocess.run(command, cwd=self.root, capture_output=True, text=True, timeout=60)

    def test_reproducible_installable_bundle_and_overwrite_guard(self):
        first, second = self.root / "first", self.root / "second"
        for output in (first, second):
            result = self.package(output)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for name in OUTPUTS:
            self.assertEqual((first / name).read_bytes(), (second / name).read_bytes())
        for line in (first / OUTPUTS[2]).read_text().splitlines():
            digest, name = line.split("  ", 1)
            self.assertEqual(hashlib.sha256((first / name).read_bytes()).hexdigest(), digest)
        game = PORT / "current"
        with zipfile.ZipFile(first / OUTPUTS[0]) as cartridge:
            expected = {path.relative_to(game).as_posix() for path in game.rglob("*") if path.is_file()}
            self.assertEqual(set(cartridge.namelist()), expected)
            for name in expected:
                self.assertEqual(cartridge.read(name), (game / name).read_bytes())
        with zipfile.ZipFile(first / OUTPUTS[1]) as bundle:
            prefix = "mr-rescue-playtest/"
            expected = {prefix + name for name in (*ATTRIBUTION, OUTPUTS[0],
                        "play-mr-rescue.sh", "play-mr-rescue.ps1", "play-mr-rescue.cmd")}
            self.assertEqual(set(bundle.namelist()), expected)
            for name in ATTRIBUTION:
                self.assertEqual(bundle.read(prefix + name), (PORT / name).read_bytes())
            self.assertEqual(bundle.read(prefix + OUTPUTS[0]), (first / OUTPUTS[0]).read_bytes())
            self.assertEqual((bundle.getinfo(prefix + "play-mr-rescue.sh").external_attr >> 16) & 0o777, 0o755)
        before = {name: (first / name).read_bytes() for name in OUTPUTS}
        self.assertNotEqual(self.package(first).returncode, 0)
        self.assertEqual(before, {name: (first / name).read_bytes() for name in OUTPUTS})

    def test_invalid_manifest_preserves_previous_delivery(self):
        fixture = self.root / "repo"
        scripts = fixture / "scripts"
        scripts.mkdir(parents=True)
        for name in ("package_release.py", "package_mr_rescue_playtest.py"):
            shutil.copyfile(ROOT / "scripts" / name, scripts / name)
        port = fixture / "demos/mr-rescue"
        shutil.copytree(PORT, port)
        output = self.root / "delivery"
        result = self.package(output)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        before = {name: (output / name).read_bytes() for name in OUTPUTS}
        with (port / "current/game.lua").open("a") as source:
            source.write("\n-- Changed after manifest generation.\n")
        result = self.package(output, scripts / "package_mr_rescue_playtest.py", replace=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(before, {name: (output / name).read_bytes() for name in OUTPUTS})

    def test_shared_archiver_preserves_binary_release_root(self):
        files = {"elis": (b"payload", 0o755)}
        for windows in (False, True):
            output = self.root / ("release.zip" if windows else "release.tar.gz")
            archive_payload(output, "release", files, windows, 0)
            if windows:
                with zipfile.ZipFile(output) as archive:
                    self.assertEqual(archive.namelist(), ["release/elis"])
                    self.assertEqual(archive.read("release/elis"), b"payload")
            else:
                with tarfile.open(output) as archive:
                    self.assertEqual(archive.getnames(), ["release/elis"])
                    self.assertEqual(archive.extractfile("release/elis").read(), b"payload")


if __name__ == "__main__":
    unittest.main()
