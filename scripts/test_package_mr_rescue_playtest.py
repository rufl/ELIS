#!/usr/bin/env python3
"""Focused, display-free regressions for the transferable playtest artifacts."""

import hashlib
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest import mock
import zipfile

import package_release

from package_release import ROOT, archive_payload, artifact_output_lock, publish_artifacts
from package_mr_rescue_playtest import ATTRIBUTION, OUTPUTS, PORT, main


class PlaytestPackaging(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="elis-playtest-package-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        environment = mock.patch.dict(os.environ, {"SOURCE_DATE_EPOCH": "0"})
        environment.start()
        self.addCleanup(environment.stop)

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

    def invoke_main(self, output, replace=False):
        arguments = ["package_mr_rescue_playtest.py", "--output", str(output)]
        if replace:
            arguments.append("--replace")
        with mock.patch.object(sys, "argv", arguments):
            main()

    def snapshot(self, output):
        return {name: ((output / name).read_bytes(), stat.S_IMODE((output / name).stat().st_mode))
                for name in OUTPUTS}

    def test_failed_replacement_restores_previous_delivery_and_releases_lock(self):
        output = self.root / "delivery"
        result = self.package(output)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for name, mode in zip(OUTPUTS, (0o640, 0o600, 0o644)):
            (output / name).chmod(mode)
        before = self.snapshot(output)
        original_replace = os.replace

        def fail_bundle(source, destination, *args, **kwargs):
            if Path(destination) == output / OUTPUTS[1] and Path(source).parent.name.startswith(".mr-rescue-stage-"):
                self.assertNotEqual((output / OUTPUTS[0]).read_bytes(), before[OUTPUTS[0]][0])
                raise OSError("injected bundle publication failure")
            return original_replace(source, destination, *args, **kwargs)

        with mock.patch.dict(os.environ, {"SOURCE_DATE_EPOCH": "946684800"}):
            with mock.patch("package_release.os.replace", side_effect=fail_bundle):
                with self.assertRaisesRegex(OSError, "injected bundle publication failure"):
                    self.invoke_main(output, replace=True)
        self.assertEqual(self.snapshot(output), before)
        self.assertEqual(set(path.name for path in output.iterdir()), set(OUTPUTS))
        with artifact_output_lock(output):
            self.assertEqual(self.snapshot(output), before)

    def test_failed_first_delivery_removes_partial_outputs_and_releases_lock(self):
        output = self.root / "delivery"
        original_link = os.link

        def fail_bundle(source, destination, *args, **kwargs):
            if Path(destination) == output / OUTPUTS[1] and Path(source).parent.name.startswith(".mr-rescue-stage-"):
                with zipfile.ZipFile(output / OUTPUTS[0]) as cartridge:
                    self.assertEqual(cartridge.read("game.lua"), (PORT / "current/game.lua").read_bytes())
                raise OSError("injected first delivery failure")
            return original_link(source, destination, *args, **kwargs)

        with mock.patch("package_release.os.link", side_effect=fail_bundle):
            with self.assertRaisesRegex(OSError, "injected first delivery failure"):
                self.invoke_main(output)
        self.assertEqual(list(output.iterdir()), [])
        with artifact_output_lock(output):
            pass

    def publication_fixture(self):
        staging, output = self.root / "stage", self.root / "delivery"
        staging.mkdir()
        output.mkdir()
        for name in ("first", "second"):
            (staging / name).write_bytes(("new " + name).encode())
        return staging, output

    def test_immutable_existing_output_is_not_overwritten(self):
        staging, output = self.publication_fixture()
        (output / "second").write_bytes(b"immutable delivery")
        with self.assertRaises((OSError, RuntimeError, ValueError)):
            publish_artifacts(staging, output, ("first", "second"))
        self.assertEqual((output / "second").read_bytes(), b"immutable delivery")
        self.assertFalse((output / "first").exists())

    def test_dangling_output_symlink_is_not_replaced(self):
        staging, output = self.publication_fixture()
        missing = self.root / "missing"
        (output / "second").symlink_to(missing)
        with self.assertRaises((OSError, RuntimeError, ValueError)):
            publish_artifacts(staging, output, ("first", "second"), replace=("second",))
        self.assertTrue((output / "second").is_symlink())
        self.assertEqual((output / "second").readlink(), missing)
        self.assertFalse(missing.exists())
        self.assertFalse((output / "first").exists())

    def test_new_output_race_preserves_competing_file(self):
        staging, output = self.publication_fixture()
        original_link = os.link

        def competing_delivery(source, destination, *args, **kwargs):
            if Path(source) == staging / "second" and Path(destination) == output / "second":
                (output / "second").write_bytes(b"competing delivery")
            return original_link(source, destination, *args, **kwargs)

        with mock.patch("package_release.os.link", side_effect=competing_delivery):
            with self.assertRaises(FileExistsError):
                publish_artifacts(staging, output, ("first", "second"))
        self.assertEqual((output / "second").read_bytes(), b"competing delivery")
        self.assertFalse((output / "first").exists())

    def test_separate_process_cannot_publish_while_output_is_locked(self):
        output = self.root / "delivery"
        result = self.package(output)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        before = self.snapshot(output)
        with artifact_output_lock(output):
            result = self.package(output, replace=True)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(self.snapshot(output), before)
            with self.assertRaises((OSError, RuntimeError)):
                with artifact_output_lock(output):
                    self.fail("A contending writer acquired the held lock")
        self.assertEqual(set(path.name for path in output.iterdir()), set(OUTPUTS))

    def test_failed_rollback_preserves_recovery_outside_staging_cleanup(self):
        output = self.root / "delivery"
        result = self.package(output)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        before = self.snapshot(output)
        original_replace = os.replace

        def fail_publication_and_restore(source, destination, *args, **kwargs):
            source, destination = Path(source), Path(destination)
            if source.parent.name.startswith(".mr-rescue-stage-") and destination == output / OUTPUTS[1]:
                raise OSError("injected bundle publication failure")
            if not source.parent.name.startswith(".mr-rescue-stage-") and destination == output / OUTPUTS[0]:
                raise OSError("injected rollback failure")
            return original_replace(source, destination, *args, **kwargs)

        with mock.patch.dict(os.environ, {"SOURCE_DATE_EPOCH": "946684800"}):
            with mock.patch("package_release.os.replace", side_effect=fail_publication_and_restore):
                with self.assertRaises(RuntimeError) as failure:
                    self.invoke_main(output, replace=True)
        recovery = [path for path in output.iterdir()
                    if path.is_dir() and path.name != ".elis-artifacts.lock"]
        self.assertEqual(len(recovery), 1)
        self.assertIn(str(recovery[0]), str(failure.exception))
        self.assertFalse(recovery[0].name.startswith(".mr-rescue-stage-"))
        recovered = [path for path in recovery[0].rglob("*") if path.is_file()]
        self.assertTrue(any(path.read_bytes() == before[OUTPUTS[0]][0] and
                            stat.S_IMODE(path.stat().st_mode) == before[OUTPUTS[0]][1]
                            for path in recovered))
        for name in OUTPUTS:
            candidates = [output / name, *recovered]
            self.assertTrue(any(path.is_file() and path.read_bytes() == before[name][0]
                                for path in candidates), f"Previous {name} is unrecoverable")
        with artifact_output_lock(output):
            pass

    def test_failed_checksum_replacement_removes_new_release_artifact(self):
        staging, output = self.publication_fixture()
        (output / "second").write_bytes(b"previous checksums")
        original_replace = os.replace

        def fail_checksums(source, destination, *args, **kwargs):
            if Path(source) == staging / "second" and Path(destination) == output / "second":
                self.assertEqual((output / "first").read_bytes(), b"new first")
                raise OSError("injected checksum publication failure")
            return original_replace(source, destination, *args, **kwargs)

        with mock.patch("package_release.os.replace", side_effect=fail_checksums):
            with self.assertRaisesRegex(OSError, "injected checksum publication failure"):
                publish_artifacts(staging, output, ("first", "second"), replace=("second",))
        self.assertEqual((output / "second").read_bytes(), b"previous checksums")
        self.assertEqual([path.name for path in output.iterdir()], ["second"])

    def test_staged_symlink_cannot_publish_external_content(self):
        staging, output = self.publication_fixture()
        external = self.root / "external"
        external.write_bytes(b"external content")
        (staging / "second").unlink()
        (staging / "second").symlink_to(external)
        with self.assertRaises((OSError, RuntimeError, ValueError)):
            publish_artifacts(staging, output, ("first", "second"))
        self.assertEqual(list(output.iterdir()), [])
        self.assertEqual(external.read_bytes(), b"external content")

    def test_destination_directory_is_never_replaced(self):
        staging, output = self.publication_fixture()
        (output / "second").mkdir()
        (output / "second/keep").write_bytes(b"directory content")
        with self.assertRaises((OSError, RuntimeError, ValueError)):
            publish_artifacts(staging, output, ("first", "second"), replace=("second",))
        self.assertEqual((output / "second/keep").read_bytes(), b"directory content")
        self.assertFalse((output / "first").exists())

    def test_unsafe_and_duplicate_names_do_not_publish(self):
        staging, output = self.publication_fixture()
        outside = self.root / "outside"
        outside.write_bytes(b"outside content")
        for names in (("../outside",), ("first", "first")):
            with self.subTest(names=names):
                with self.assertRaises((OSError, RuntimeError, ValueError)):
                    publish_artifacts(staging, output, names)
                self.assertEqual(list(output.iterdir()), [])
                self.assertEqual(outside.read_bytes(), b"outside content")

    def test_binary_release_extends_existing_checksums_without_changing_old_artifacts(self):
        executable = Path(sys.executable).read_bytes()
        if executable[:6] != b"\x7fELF\x02\x01" or executable[18:20] != b"\x3e\x00":
            self.skipTest("Requires a real Linux x86_64 Python executable")
        fixture = self.root / "release-source"
        fixture.mkdir()
        for name in (*package_release.SOURCE_FILES, "demos/catalog.txt"):
            destination = fixture / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, destination)
        binaries = fixture / "zig-out/bin"
        binaries.mkdir(parents=True)
        for name in ("elis", "elis-studio"):
            (binaries / name).write_bytes(executable)
        commands = (
            ["git", "init", "--quiet"],
            ["git", "-c", "user.name=Packaging Test", "-c", "user.email=packaging@example.invalid",
             "-c", "commit.gpgsign=false", "-c", f"core.hooksPath={os.devnull}",
             "commit", "--quiet", "--allow-empty", "-m", "Packaging fixture"],
        )
        for command in commands:
            result = subprocess.run(command, cwd=fixture, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        output = self.root / "releases"
        first = {}
        with mock.patch.object(package_release, "ROOT", fixture):
            with mock.patch.object(package_release, "linux_libraries", return_value={}):
                for version in ("1.2.3", "1.2.4"):
                    arguments = ["package_release.py", "--platform", "linux-x86_64",
                                 "--version", version, "--output", str(output)]
                    with mock.patch.object(sys, "argv", arguments):
                        package_release.main()
                    if version == "1.2.3":
                        first = {path.name: path.read_bytes() for path in output.iterdir()
                                 if path.name != "SHA256SUMS"}
        for name, data in first.items():
            self.assertEqual((output / name).read_bytes(), data)
        expected = {f"elis-{version}-linux-x86_64{suffix}"
                    for version in ("1.2.3", "1.2.4")
                    for suffix in (".tar.gz", ".manifest.json")}
        rows = [line.split("  ", 1) for line in (output / "SHA256SUMS").read_text().splitlines()]
        self.assertEqual(sorted(name for _, name in rows), sorted(expected))
        self.assertEqual({path.name for path in output.iterdir()}, expected | {"SHA256SUMS"})
        for digest, name in rows:
            self.assertEqual(hashlib.sha256((output / name).read_bytes()).hexdigest(), digest)

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
