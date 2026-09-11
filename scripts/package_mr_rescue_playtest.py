#!/usr/bin/env python3
"""Build an audited Mr. Rescue playtest cartridge and cross-platform launch bundle.

No build, download, or hardware approval is performed. Extract the bundle under
an existing ELIS installation's games/ directory, then use its play launcher.
"""

import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from package_release import ROOT, archive_payload, safe_file, sha256

PORT = ROOT / "demos/mr-rescue"
OUTPUTS = ("mr-rescue.lupi", "mr-rescue-playtest.zip", "mr-rescue-playtest.SHA256SUMS")
ATTRIBUTION = ("README.md", "PARITY.md", "SOURCE.md", "LICENSE.upstream", "CC-BY-SA-3.0.txt")

LINUX_LAUNCHER = r'''#!/bin/sh
set -eu
bundle=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$bundle/../.." && pwd)
if [ ! -f "$bundle/mr-rescue.lupi" ]; then
    echo "Missing mr-rescue.lupi beside this launcher." >&2
    exit 1
fi
if [ -x "$root/elis" ]; then
    executable="$root/elis"
elif [ -x "$root/zig-out/bin/elis" ]; then
    executable="$root/zig-out/bin/elis"
else
    echo "ELIS not found. Extract this bundle under ELIS_ROOT/games/." >&2
    exit 1
fi
cd -- "$root"
exec "$executable" "$bundle/mr-rescue.lupi"
'''

WINDOWS_LAUNCHER = r'''$ErrorActionPreference = 'Stop'
try {
    $root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $cartridge = Join-Path $PSScriptRoot 'mr-rescue.lupi'
    if (-not (Test-Path -LiteralPath $cartridge -PathType Leaf)) {
        throw 'Missing mr-rescue.lupi beside this launcher.'
    }
    $executable = Join-Path $root 'elis.exe'
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        $executable = Join-Path $root 'zig-out/bin/elis.exe'
    }
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw 'ELIS not found. Extract this bundle under ELIS_ROOT/games/.'
    }
    Push-Location -LiteralPath $root
    try {
        & $executable $cartridge
        $status = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    exit $status
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
'''

WINDOWS_SHORTCUT = r'''@echo off
setlocal DisableDelayedExpansion
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0play-mr-rescue.ps1"
set "status=%errorlevel%"
if not "%status%"=="0" pause
exit /b %status%
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="dist", help="Artifact directory (default: dist)")
    parser.add_argument("--replace", action="store_true", help="Replace existing local playtest artifacts")
    args = parser.parse_args()
    output = Path(args.output).absolute()
    if any(path.is_symlink() for path in (output, *output.parents)):
        parser.error("--output must not traverse symlinks")
    output = output.resolve()
    if output == ROOT or output in ROOT.parents or any(
        output == ROOT / name or ROOT / name in output.parents
        for name in ("src", "scripts", "example", "mazestein3d", "demos", "LICENSES", ".git", "zig-out")
    ):
        parser.error("--output must not overwrite source or build input directories")
    for name in OUTPUTS:
        target = output / name
        if target.is_symlink() or (target.exists() and (not args.replace or not target.is_file())):
            parser.error(f"Refusing to replace {target}; use --replace for regular playtest artifacts")
    try:
        epoch = int(os.environ.get("SOURCE_DATE_EPOCH", "0"))
    except ValueError:
        parser.error("SOURCE_DATE_EPOCH must be an integer")
    if not 0 <= epoch <= 0xFFFFFFFF:
        parser.error("SOURCE_DATE_EPOCH must be in [0, 4294967295]")

    subprocess.run([sys.executable, str(PORT / "tools/audit_release.py")], check=True)
    game = PORT / "current"
    files = {}
    for path in game.rglob("*"):
        if path.is_symlink():
            raise RuntimeError(f"Cartridge inputs must not be symlinks: {path}")
        if path.is_file():
            files[path.relative_to(game).as_posix()] = (safe_file(path), 0o644)
    if sum(len(data) for data, _ in files.values()) > 16 * 1024 * 1024:
        raise RuntimeError("Cartridge exceeds the 16 MiB release limit")
    bundle = {name: (safe_file(PORT / name), 0o644) for name in ATTRIBUTION}
    bundle["play-mr-rescue.sh"] = (LINUX_LAUNCHER.encode(), 0o755)
    bundle["play-mr-rescue.ps1"] = (WINDOWS_LAUNCHER.replace("\n", "\r\n").encode(), 0o644)
    bundle["play-mr-rescue.cmd"] = (WINDOWS_SHORTCUT.replace("\n", "\r\n").encode(), 0o644)

    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".mr-rescue-stage-", dir=output) as temporary:
        staging = Path(temporary)
        archive_payload(staging / OUTPUTS[0], "", files, True, epoch)
        bundle[OUTPUTS[0]] = (safe_file(staging / OUTPUTS[0]), 0o644)
        archive_payload(staging / OUTPUTS[1], "mr-rescue-playtest", bundle, True, epoch)
        checksums = "".join(f"{sha256(safe_file(staging / name))}  {name}\n" for name in OUTPUTS[:2])
        (staging / OUTPUTS[2]).write_text(checksums, encoding="utf-8", newline="\n")
        for name in OUTPUTS:
            os.replace(staging / name, output / name)
    print(checksums, end="")
    print(output / OUTPUTS[1])


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Playtest packaging failed: {error}")
