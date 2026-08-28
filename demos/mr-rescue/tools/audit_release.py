#!/usr/bin/env python3
"""Fail-closed cartridge manifest, use, and attribution audit."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "current"
EXPECTED_REVISION = "a5be73c60acb8d1be506f7b5e48e784492ba96ce"
DYNAMIC_ASSET = re.compile(
    r"^(human_[1-4]_|award_[1-6]_|howto_[0-8]_(?:left|right)$|"
    r"(?:shockwave|circle)_[0-9]$|"
    r"(?:magmahulk|gasleak|charcoal)_portrait_[0-3]$)"
)


def fail(message: str) -> None:
    raise SystemExit(message)


def main() -> None:
    for required in ("LICENSE.upstream", "CC-BY-SA-3.0.txt", "SOURCE.md"):
        if not (ROOT / required).is_file():
            fail(f"missing attribution file: {required}")
    if EXPECTED_REVISION not in (ROOT / "SOURCE.md").read_text(encoding="utf-8"):
        fail("SOURCE.md does not pin the audited revision")

    entries: dict[str, int] = {}
    for line in (GAME / "lupi_manifest.txt").read_text(encoding="utf-8").splitlines():
        fields = line.split(" ", 3)
        if len(fields) != 4:
            fail(f"malformed manifest line: {line}")
        size = int(fields[1])
        relative = fields[2]
        if relative in entries:
            fail(f"duplicate manifest path: {relative}")
        entries[relative] = size

    payload = {
        path.relative_to(GAME).as_posix(): path.stat().st_size
        for path in GAME.rglob("*")
        if path.is_file() and path.name != "lupi_manifest.txt"
    }
    if entries != payload:
        missing = sorted(set(payload) - set(entries))
        stale = sorted(set(entries) - set(payload))
        wrong = sorted(path for path in entries.keys() & payload.keys()
                       if entries[path] != payload[path])
        fail(f"manifest mismatch: missing={missing}, stale={stale}, wrong={wrong}")

    lua_source = "\n".join(
        path.read_text(encoding="utf-8") for path in sorted(GAME.glob("*.lua"))
    )
    for relative in sorted(entries):
        if relative.startswith("assets/"):
            name = relative.removeprefix("assets/")
            if f'assets/{name}' not in lua_source and not DYNAMIC_ASSET.match(name):
                fail(f"release bitmap has no runtime reference: {relative}")
        elif relative.startswith("music/"):
            if relative not in lua_source:
                fail(f"release music has no runtime reference: {relative}")
        elif not relative.endswith(".lua"):
            fail(f"unexpected release payload: {relative}")

    print(f"Mr. Rescue release audit: pass ({sum(entries.values())} payload bytes)")


if __name__ == "__main__":
    main()
