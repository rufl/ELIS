#!/usr/bin/env python3
"""Validate a named-board Mr. Rescue hardware proof record.

This tool does not measure hardware. A board runner must first write a record
with raw evidence paths and measured samples. The validator binds that record
to one exact cartridge hash and rejects incomplete or over-budget evidence.
"""

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
import math
from pathlib import Path
import os
import tempfile
from typing import Any

SCHEMA = "elis.mr-rescue-hardware/v1"
FRAME_TIME_LIMIT_MS = 1000 / 60
LUA_MEMORY_LIMIT_BYTES = 4 * 1024 * 1024
CARTRIDGE_LIMIT_BYTES = 16 * 1024 * 1024
BITMAP_LIMIT_PIXELS = 49_152
SOAK_LIMIT_SECONDS = 30 * 60
REQUIRED_SOAK_FLAGS = (
    "crash",
    "reset",
    "input_lockup",
    "renderer_corruption",
    "memory_growth",
)
REQUIRED_EVIDENCE = ("frame_time", "memory", "soak")


class ProofError(ValueError):
    """The supplied hardware evidence is not sufficient for approval."""


def _mapping(value: Any, name: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ProofError(f"{name} must be an object")
    return value


def _text(value: Any, name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ProofError(f"{name} must be a non-empty string")
    return value.strip()


def _integer(value: Any, name: str, minimum: int = 0) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise ProofError(f"{name} must be an integer >= {minimum}")
    return value


def _number(value: Any, name: str, minimum: float = 0.0) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ProofError(f"{name} must be a finite number >= {minimum}")
    number = float(value)
    if not math.isfinite(number) or number < minimum:
        raise ProofError(f"{name} must be a finite number >= {minimum}")
    return number


def _samples(value: Any, name: str) -> list[float]:
    if not isinstance(value, list) or len(value) < 2:
        raise ProofError(f"{name} must contain at least two samples")
    return [_number(sample, f"{name}[{index}]") for index, sample in enumerate(value)]


def _timestamp(value: Any, name: str) -> str:
    text = _text(value, name)
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError as error:
        raise ProofError(f"{name} must be an ISO-8601 timestamp") from error
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ProofError(f"{name} must include a timezone offset")
    return text


def _regular_file(value: Any, name: str) -> Path:
    path = (
        value.expanduser()
        if isinstance(value, Path)
        else Path(_text(value, name)).expanduser()
    )
    if path.is_symlink() or not path.is_file():
        raise ProofError(f"{name} must name a regular non-symlink file")
    return path.resolve()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def validate_record(record: dict[str, Any], cartridge_path: Path) -> dict[str, Any]:
    if record.get("schema") != SCHEMA:
        raise ProofError(f"schema must be {SCHEMA}")

    board = _mapping(record.get("board"), "board")
    board_name = _text(board.get("name"), "board.name")
    firmware = _text(board.get("firmware"), "board.firmware")
    build_config = _text(board.get("build_config"), "board.build_config")
    measurement_tool = _text(board.get("measurement_tool"), "board.measurement_tool")
    source_commit = _text(record.get("source_commit"), "source_commit")
    started_at = _timestamp(record.get("started_at"), "started_at")
    ended_at = _timestamp(record.get("ended_at"), "ended_at")
    started_value = datetime.fromisoformat(started_at.replace("Z", "+00:00"))
    ended_value = datetime.fromisoformat(ended_at.replace("Z", "+00:00"))
    if ended_value <= started_value:
        raise ProofError("ended_at must be after started_at")

    cartridge = _mapping(record.get("cartridge"), "cartridge")
    expected_hash = _text(cartridge.get("sha256"), "cartridge.sha256").lower()
    if len(expected_hash) != 64 or any(character not in "0123456789abcdef" for character in expected_hash):
        raise ProofError("cartridge.sha256 must be a lowercase SHA-256 digest")
    expected_size = _integer(cartridge.get("size_bytes"), "cartridge.size_bytes", 1)
    if expected_size > CARTRIDGE_LIMIT_BYTES:
        raise ProofError("cartridge.size_bytes exceeds the 16 MiB release limit")
    actual_size = cartridge_path.stat().st_size
    actual_hash = sha256(cartridge_path)
    if actual_size != expected_size:
        raise ProofError(
            f"cartridge size mismatch: record={expected_size}, actual={actual_size}"
        )
    if actual_hash != expected_hash:
        raise ProofError(
            f"cartridge hash mismatch: record={expected_hash}, actual={actual_hash}"
        )

    measurements = _mapping(record.get("measurements"), "measurements")
    frame_samples = _samples(measurements.get("frame_time_ms"), "measurements.frame_time_ms")
    memory_samples = _samples(
        measurements.get("lua_memory_bytes"), "measurements.lua_memory_bytes"
    )
    if any(not float(sample).is_integer() for sample in memory_samples):
        raise ProofError("measurements.lua_memory_bytes must contain integers")
    memory_samples_int = [int(sample) for sample in memory_samples]
    worst_frame = max(frame_samples)
    peak_memory = max(memory_samples_int)
    if worst_frame > FRAME_TIME_LIMIT_MS:
        raise ProofError(
            f"worst frame time {worst_frame:.6f} ms exceeds {FRAME_TIME_LIMIT_MS:.6f} ms"
        )
    if peak_memory > LUA_MEMORY_LIMIT_BYTES:
        raise ProofError(
            f"peak Lua memory {peak_memory} exceeds {LUA_MEMORY_LIMIT_BYTES} bytes"
        )
    if measurements.get("manifest_exact") is not True:
        raise ProofError("measurements.manifest_exact must be true")
    max_bitmap_pixels = _integer(
        measurements.get("max_bitmap_pixels"), "measurements.max_bitmap_pixels", 1
    )
    if max_bitmap_pixels > BITMAP_LIMIT_PIXELS:
        raise ProofError(
            f"largest bitmap {max_bitmap_pixels} pixels exceeds {BITMAP_LIMIT_PIXELS}"
        )

    soak = _mapping(record.get("soak"), "soak")
    soak_seconds = _integer(soak.get("duration_seconds"), "soak.duration_seconds")
    elapsed_seconds = (ended_value - started_value).total_seconds()
    if soak_seconds > elapsed_seconds:
        raise ProofError("soak duration exceeds the evidence interval")
    if soak_seconds < SOAK_LIMIT_SECONDS:
        raise ProofError(
            f"soak duration {soak_seconds} seconds is shorter than {SOAK_LIMIT_SECONDS}"
        )
    for flag in REQUIRED_SOAK_FLAGS:
        if soak.get(flag) is not False:
            raise ProofError(f"soak.{flag} must be false")

    evidence = _mapping(record.get("evidence"), "evidence")
    evidence_paths = {
        name: _regular_file(evidence.get(name), f"evidence.{name}")
        for name in REQUIRED_EVIDENCE
    }
    evidence_details = {
        name: {
            "path": str(path),
            "sha256": sha256(path),
            "size_bytes": path.stat().st_size,
        }
        for name, path in evidence_paths.items()
    }

    return {
        "schema": SCHEMA,
        "status": "passed",
        "board": {
            "name": board_name,
            "firmware": firmware,
            "build_config": build_config,
            "measurement_tool": measurement_tool,
        },
        "source_commit": source_commit,
        "started_at": started_at,
        "ended_at": ended_at,
        "cartridge": {
            "path": str(cartridge_path),
            "sha256": actual_hash,
            "size_bytes": actual_size,
        },
        "measurements": {
            "frame_time_ms": {
                "sample_count": len(frame_samples),
                "worst": round(worst_frame, 6),
                "limit": round(FRAME_TIME_LIMIT_MS, 6),
            },
            "lua_memory_bytes": {
                "sample_count": len(memory_samples_int),
                "peak": peak_memory,
                "limit": LUA_MEMORY_LIMIT_BYTES,
            },
            "manifest_exact": True,
            "max_bitmap_pixels": max_bitmap_pixels,
            "max_bitmap_limit": BITMAP_LIMIT_PIXELS,
        },
        "soak": {
            "duration_seconds": soak_seconds,
            **{flag: False for flag in REQUIRED_SOAK_FLAGS},
        },
        "evidence": evidence_details,
    }


def write_json(path: Path, payload: dict[str, Any], replace: bool) -> None:
    if path.is_symlink() or (path.exists() and not replace):
        raise ProofError(f"refusing to replace existing proof record: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        raise ProofError(f"proof output must not be a symlink: {path}")
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(payload, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--record", type=Path, required=True, help="Raw board evidence JSON")
    parser.add_argument("--cartridge", type=Path, required=True, help="Exact cartridge tested")
    parser.add_argument("--output", type=Path, required=True, help="Proof record JSON")
    parser.add_argument("--replace", action="store_true", help="Replace an existing output")
    args = parser.parse_args()

    try:
        record = json.loads(args.record.read_text(encoding="utf-8"))
        record = _mapping(record, "record")
        cartridge = _regular_file(args.cartridge, "--cartridge")
        proof = validate_record(record, cartridge)
        write_json(args.output, proof, args.replace)
    except (OSError, json.JSONDecodeError, ProofError) as error:
        parser.error(str(error))
    print(
        "Mr. Rescue named-board hardware proof: pass "
        f"({proof['board']['name']}, {proof['cartridge']['sha256']})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
