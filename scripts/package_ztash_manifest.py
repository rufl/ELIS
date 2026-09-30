#!/usr/bin/env python3
"""Create an immutable ZTASH manifest for verified ELIS release archives."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile


APPLICATION = "elis"
SCHEMA = "ztash-release-v1"
MAX_ARCHIVE_BYTES = 256 * 1024 * 1024
SEMVER = re.compile(
    r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-((?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
    r"(?:\.(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?"
    r"(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
)
COMMIT = re.compile(r"[0-9a-f]{40}")
TARGETS = (
    ("x86_64-linux", "linux-x86_64", ".tar.gz"),
    ("x86_64-windows-gnu", "windows-x86_64", ".zip"),
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def parse_artifacts(values: list[str]) -> dict[str, Path]:
    artifacts: dict[str, Path] = {}
    for value in values:
        target, separator, raw_path = value.partition("=")
        if not separator or not target or not raw_path:
            raise ValueError("Artifacts must use TARGET=PATH")
        if target in artifacts:
            raise ValueError(f"Duplicate artifact target: {target}")
        artifacts[target] = Path(raw_path)
    return artifacts


def archive_entry(path: Path, expected_name: str, target: str) -> dict[str, object]:
    try:
        metadata = path.lstat()
    except FileNotFoundError as error:
        raise ValueError(f"Missing release archive: {path}") from error
    if path.is_symlink() or not stat.S_ISREG(metadata.st_mode):
        raise ValueError(f"Release archive must be a regular non-symlink file: {path}")
    if path.name != expected_name:
        raise ValueError(f"Unexpected {target} archive name: {path.name}")
    if metadata.st_size <= 0 or metadata.st_size > MAX_ARCHIVE_BYTES:
        raise ValueError(f"Release archive size is outside the ZTASH limit: {path}")
    return {
        "target": target,
        "name": expected_name,
        "size_bytes": metadata.st_size,
        "sha256": sha256_file(path),
    }


def build_manifest(
    version: str,
    build_id: str,
    source_commit: str,
    source_date_epoch: int,
    artifacts: dict[str, Path],
) -> dict[str, object]:
    version_match = SEMVER.fullmatch(version)
    if version_match is None or version_match.group(4) is None:
        raise ValueError("ZTASH publication requires an explicit semantic prerelease")
    if COMMIT.fullmatch(source_commit) is None:
        raise ValueError("Source commit must be a lowercase 40-character Git SHA")
    if build_id != source_commit:
        raise ValueError("ELIS ZTASH build ID must equal the immutable source commit")
    if source_date_epoch <= 0:
        raise ValueError("Source date epoch must be positive")

    expected_targets = {target for target, _, _ in TARGETS}
    if set(artifacts) != expected_targets:
        raise ValueError("ZTASH manifest requires exactly the Linux and Windows x86-64 archives")

    entries = []
    resolved_paths = set()
    for target, platform, suffix in TARGETS:
        path = artifacts[target]
        resolved = path.resolve(strict=True)
        if resolved in resolved_paths:
            raise ValueError("ZTASH targets must use distinct archives")
        resolved_paths.add(resolved)
        expected_name = f"elis-{version}-{platform}{suffix}"
        entries.append(archive_entry(path, expected_name, target))

    return {
        "schema": SCHEMA,
        "application": APPLICATION,
        "version": version,
        "build_id": build_id,
        "source_commit": source_commit,
        "source_date_epoch": source_date_epoch,
        "artifacts": entries,
    }


def write_manifest(path: Path, manifest: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() or path.is_symlink():
        raise ValueError(f"Refusing to replace ZTASH manifest: {path}")
    payload = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o644)
        os.link(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-id", required=True)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--source-date-epoch", required=True, type=int)
    parser.add_argument("--artifact", action="append", default=[], metavar="TARGET=PATH")
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()
    manifest = build_manifest(
        arguments.version,
        arguments.build_id,
        arguments.source_commit,
        arguments.source_date_epoch,
        parse_artifacts(arguments.artifact),
    )
    write_manifest(arguments.output, manifest)
    print(arguments.output)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"ZTASH manifest failed: {error}", file=sys.stderr)
        sys.exit(1)
